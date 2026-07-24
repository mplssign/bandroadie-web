-- Fix: setlist positions trigger collision on delete
--
-- Root Cause:
-- The AFTER DELETE trigger `reorder_setlist_positions_on_delete` uses ROW_NUMBER()
-- (1-indexed) to renumber all rows in a setlist after deletion, but the unique
-- constraint `setlist_songs_setlist_id_position_key (setlist_id, position)` is
-- NOT DEFERRABLE. This causes transient collisions during multi-row UPDATE:
-- when updating position 0→1, position 1 still exists (not yet updated to 2),
-- triggering "duplicate key value" error.
--
-- This affects ALL delete operations on setlist_songs:
-- - move_song_between_setlists RPC (DELETE phase)
-- - delete_song_from_setlist RPC
-- - deleteSongFromCatalog (cascades across all setlists)
-- - Special item deletion (set breaks/pauses)
-- - Setlist cascade deletes
--
-- Fix Strategy:
-- 1. Make constraint DEFERRABLE INITIALLY DEFERRED (checks at transaction end)
-- 2. Replace wholesale ROW_NUMBER() renumbering with surgical decrement
--    (only updates positions > deleted position, preserves 0-indexing)
--
-- Evidence: Production setlists have position gaps [0,1,4,5,...] proving
-- the trigger fails intermittently under current NOT DEFERRABLE constraint.

-- Part 1: Make unique constraint deferrable
ALTER TABLE public.setlist_songs
  DROP CONSTRAINT setlist_songs_setlist_id_position_key;

ALTER TABLE public.setlist_songs
  ADD CONSTRAINT setlist_songs_setlist_id_position_key
  UNIQUE (setlist_id, position)
  DEFERRABLE INITIALLY DEFERRED;

-- Part 2: Replace wholesale renumbering with surgical decrement
CREATE OR REPLACE FUNCTION public.reorder_setlist_positions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Instead of renumbering everything with ROW_NUMBER(),
  -- just decrement positions greater than the deleted position
  UPDATE public.setlist_songs
  SET position = position - 1
  WHERE setlist_id = OLD.setlist_id
    AND position > OLD.position;

  RETURN OLD;
END;
$$;
