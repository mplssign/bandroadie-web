-- Ensure Figrin D'an and the Modal Nodes has at least one potential gig
-- in already-seeded demo data.

UPDATE public.gigs
SET is_potential = true
WHERE id = '00000000-0000-4000-8302-000000000004'::uuid
  AND band_id = '00000000-0000-4000-8100-000000000002'::uuid;
