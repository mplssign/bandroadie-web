-- ============================================================================
-- Migration: 20260908120000_fix_demo_auth_user_cleanup.sql
-- bug/demo-session-cleanup-orphaned-anonymous-users
--
-- Both demo teardown paths (this cron sweep and the client-invoked
-- exit_demo_session() RPC) delete the demo_sessions ledger row and cascade
-- the visitor's cloned bands, but never touch the visitor's anonymous
-- auth.users row, leaving it orphaned forever. This migration rewrites
-- cleanup_expired_demo_sessions() to also delete the now-unreferenced
-- auth.users rows (guarded against the setlists.created_by/gigs.created_by
-- ON DELETE NO ACTION back-references), and one-time backfills the
-- already-orphaned rows accumulated before this fix.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- cleanup_expired_demo_sessions() — rewritten to also clean up auth.users
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_user_ids uuid[];
  v_user_id uuid;
BEGIN
  SELECT array_agg(auth_user_id) INTO v_expired_user_ids
  FROM public.demo_sessions
  WHERE expires_at < now();

  IF v_expired_user_ids IS NULL THEN
    RETURN;
  END IF;

  -- Deleting the demo_sessions rows cascades to:
  --   bands.demo_session_id → ON DELETE CASCADE → deletes both clone bands
  --   clone bands' band_id FK → ON DELETE CASCADE → deletes all child rows,
  --     including any setlists/gigs rows referencing the visitor via created_by
  DELETE FROM public.demo_sessions WHERE auth_user_id = ANY(v_expired_user_ids);

  -- Per-user loop, each guarded independently: a FK violation on one user
  -- (e.g. a lingering setlists/gigs.created_by reference) must not abort the
  -- whole batch — a single batched DELETE would roll back every other,
  -- otherwise-clean user too, and since their demo_sessions row is already
  -- gone, they'd never be picked up by a future sweep and become permanent
  -- orphans instead of being retried.
  FOREACH v_user_id IN ARRAY v_expired_user_ids LOOP
    BEGIN
      DELETE FROM auth.users WHERE id = v_user_id;
    EXCEPTION
      WHEN foreign_key_violation THEN
        RAISE WARNING 'cleanup_expired_demo_sessions: FK violation deleting auth.users id %; left for next sweep', v_user_id;
    END;
  END LOOP;
END;
$$;

-- pg_cron calls this as the postgres superuser — not callable from clients.
REVOKE ALL ON FUNCTION public.cleanup_expired_demo_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_demo_sessions() TO postgres;

-- ─────────────────────────────────────────────────────────────────────────────
-- One-time historical backfill — clean up already-orphaned anon auth.users
-- rows accumulated before this fix. Excludes the 13 template-fixture accounts
-- (marked raw_user_meta_data->>'demo_placeholder' = 'true') and defends against
-- the same setlists/gigs.created_by FK ordering constraint as above.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_deleted_count integer;
BEGIN
  DELETE FROM auth.users
  WHERE is_anonymous = true
    AND (raw_user_meta_data->>'demo_placeholder') IS DISTINCT FROM 'true'
    AND NOT EXISTS (SELECT 1 FROM public.demo_sessions WHERE auth_user_id = auth.users.id)
    AND NOT EXISTS (SELECT 1 FROM public.setlists    WHERE created_by    = auth.users.id)
    AND NOT EXISTS (SELECT 1 FROM public.gigs        WHERE created_by    = auth.users.id);

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RAISE NOTICE 'backfill deleted % orphaned anon auth.users rows', v_deleted_count;
END $$;
