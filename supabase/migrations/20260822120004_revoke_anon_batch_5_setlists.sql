-- ============================================================================
-- BATCH 5: Revoke anon/PUBLIC execute from setlist mutation functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call setlist mutation functions
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
-- 
-- WARNING (Category E — Out of scope for this feature):
-- These 5 functions have NO internal authorization check (no is_band_member call).
-- Revoking anon access is correct, but they remain vulnerable to cross-tenant
-- authenticated calls. Fixing the missing auth check requires function body
-- changes and is tracked as a separate Critical bug.
-- 
-- This migration only closes the anon-access gap. Authenticated users can still
-- tamper with any band's setlists until the separate auth-check fix ships.
-- ============================================================================

-- Setlist function 1: add_special_item_to_setlist
REVOKE ALL ON FUNCTION add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text) TO authenticated;

-- Setlist function 2: ensure_catalog_setlist
REVOKE ALL ON FUNCTION ensure_catalog_setlist(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ensure_catalog_setlist(p_band_id uuid) TO authenticated;

-- Setlist function 3: increment_setlist_positions
REVOKE ALL ON FUNCTION increment_setlist_positions(p_setlist_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION increment_setlist_positions(p_setlist_id uuid) TO authenticated;

-- Setlist function 4: reorder_setlist_items
REVOKE ALL ON FUNCTION reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[]) TO authenticated;

-- Setlist function 5: reorder_setlist_songs
REVOKE ALL ON FUNCTION reorder_setlist_songs(p_setlist_id uuid, p_row_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reorder_setlist_songs(p_setlist_id uuid, p_row_ids uuid[]) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- All 5 functions had PUBLIC grant in pre-migration state.
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION ensure_catalog_setlist(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION increment_setlist_positions(p_setlist_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[]) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION reorder_setlist_songs(p_setlist_id uuid, p_row_ids uuid[]) TO PUBLIC;
