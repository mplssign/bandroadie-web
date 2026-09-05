-- ============================================================================
-- Migration: 20260904120005_cleanup_demo_sessions_cron.sql
-- cleanup_expired_demo_sessions() — sweeps expired demo sessions.
-- pg_cron schedule: every 5 minutes.
--
-- NOTE: If pg_cron cannot be enabled on this Supabase tier, Tony should pause
-- this migration and follow up with an Edge Function fallback feature.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Pre-check: pg_cron must already be installed via a preceding COMMITTED
-- transaction (Supabase Dashboard → Database → Extensions, or a dedicated
-- CREATE EXTENSION run in its own transaction). Enabling the extension in the
-- SAME transaction that calls cron.schedule() is the leading suspect for the
-- job silently failing to register, so this file no longer creates it — it
-- fails loudly if pg_cron is missing instead.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'pg_cron extension is not installed. Enable it via Supabase Dashboard → Database → Extensions in its own transaction, then re-apply this migration.';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- cleanup_expired_demo_sessions()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.demo_sessions
  WHERE expires_at < now();
$$;

-- pg_cron calls this as the postgres superuser — not callable from clients.
REVOKE ALL ON FUNCTION public.cleanup_expired_demo_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_demo_sessions() TO postgres;

-- Schedule: run every 5 minutes.
-- Unschedule first so a re-apply always registers a clean job definition; the
-- DO block swallows the "job not found" error on the first apply.
DO $$
BEGIN
  PERFORM cron.unschedule('cleanup_demo_sessions');
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN OTHERS THEN NULL;  -- pg_cron raises a generic exception when the job is absent
END $$;

-- Fully qualify the function — pg_cron's background worker runs with a reset
-- search_path and cannot resolve an unqualified name.
SELECT cron.schedule(
  'cleanup_demo_sessions',
  '*/5 * * * *',
  $$SELECT public.cleanup_expired_demo_sessions()$$
);

-- Post-assertion: prove the job registered, or fail loudly with a specific
-- message identifying the missing invariant.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_demo_sessions') THEN
    RAISE EXCEPTION 'cron.schedule() completed without error but cleanup_demo_sessions is not in cron.job. Check pg_cron install, role privileges on the cron schema, and that this file was applied against the pg_cron-hosting database.';
  END IF;
END $$;
