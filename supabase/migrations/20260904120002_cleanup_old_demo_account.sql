-- ============================================================================
-- Migration: 20260904120002_cleanup_old_demo_account.sql
-- Retires the shared hello@bandroadie.com demo account and its three bands.
--
-- MUST run AFTER 20260904120001_seed_demo_templates.sql.
-- DO-block guard raises if the template bands from migration 120001 do not
-- yet exist, preventing out-of-order application.
-- ============================================================================

DO $$
BEGIN
  -- Guard: verify both template bands exist before proceeding with cleanup.
  -- If this raises, Tony applied migrations out of order — stop here.
  IF NOT EXISTS (
    SELECT 1 FROM public.bands
    WHERE id = '00000000-0000-4000-8100-000000000001'
      AND is_demo_template = true
  ) THEN
    RAISE EXCEPTION
      'Template band 00000000-0000-4000-8100-000000000001 (The Banana Stand) '
      'not found. Apply 20260904120001_seed_demo_templates.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.bands
    WHERE id = '00000000-0000-4000-8100-000000000002'
      AND is_demo_template = true
  ) THEN
    RAISE EXCEPTION
      'Template band 00000000-0000-4000-8100-000000000002 (Modal Nodes) '
      'not found. Apply 20260904120001_seed_demo_templates.sql first.';
  END IF;
END;
$$;

-- Delete the old stray "Test" band and old Banana Stand / Huge Mistake.
-- CASCADE on band_id FK removes all child rows (band_members, songs, setlists,
-- setlist_songs, gigs, rehearsals, contacts, venues, financial_entries).
DELETE FROM public.bands
WHERE id IN (
  'e89bea44-8dd4-4e3d-b527-c0f75e94aa7d',   -- old The Banana Stand
  'f9184316-d670-40a5-8409-6197bd53147e',   -- old Huge Mistake
  'fc379e2d-5ab9-474b-ad0f-34b0e17f23e6'    -- stray Test band
);

-- Re-home any remaining created_by references from the retired shared demo user
-- to the seeded demo system user so FK constraints stay valid.
UPDATE public.bands
SET created_by = '00000000-0000-4000-8000-000000000001'
WHERE created_by = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';

UPDATE public.gigs
SET created_by = '00000000-0000-4000-8000-000000000001'
WHERE created_by = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';

UPDATE public.setlists
SET created_by = '00000000-0000-4000-8000-000000000001'
WHERE created_by = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';

UPDATE public.financial_entries
SET created_by = '00000000-0000-4000-8000-000000000001'
WHERE created_by = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';

-- Remove matching profile row first, then auth row.
DELETE FROM public.users
WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';

-- Delete the old shared demo auth.users row.
-- ON DELETE CASCADE on band_members.user_id cleans up any surviving memberships.
DELETE FROM auth.users
WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';
