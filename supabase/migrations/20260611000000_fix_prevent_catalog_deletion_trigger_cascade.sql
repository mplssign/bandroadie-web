-- ============================================================================
-- Migration: fix_prevent_catalog_deletion_trigger_cascade
-- Date: 2026-06-11
-- Branch: bug/fix-catalog-deletion-trigger
-- ============================================================================
-- Problem:
--   prevent_catalog_deletion() raised unconditionally on any DELETE of a
--   Catalog setlist row. This blocked cascade/system cleanup paths (e.g.
--   delete_band RPC) that legitimately delete Catalog rows during teardown.
--
-- Fix:
--   Add a pg_trigger_depth() guard so the exception is raised only when the
--   DELETE is direct (depth = 0). Nested/cascade contexts (depth > 0) are
--   allowed through, enabling band and account deletion flows to succeed.
--
-- What does NOT change:
--   - Trigger name:  prevent_catalog_deletion_trigger  (untouched)
--   - Trigger attachment:  BEFORE DELETE ON public.setlists (untouched)
--   - Exception message text: 'Cannot delete Catalog setlist'
--   - RLS policies, RPC signatures, table schema: all untouched
-- ============================================================================

CREATE OR REPLACE FUNCTION public.prevent_catalog_deletion()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
AS $function$
BEGIN
  -- Allow cascade deletes (band deletion, account teardown, etc.)
  -- pg_trigger_depth() > 0 means we are inside a cascade; allow the delete.
  IF pg_trigger_depth() > 0 THEN
    RETURN OLD;
  END IF;

  IF OLD.setlist_type = 'catalog' OR OLD.is_catalog = true THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;
  RETURN OLD;
END;
$function$;
