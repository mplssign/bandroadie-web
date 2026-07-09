-- ============================================================================
-- DRY-RUN: Backfill cross-band block_dates for Tony's historical events
-- ============================================================================
-- Purpose: Show exactly which block_dates rows would be inserted
--          WITHOUT actually inserting them.
-- 
-- Run this in Supabase Dashboard > SQL Editor to see what the backfill
-- would create before giving approval.
--
-- Tony's Details:
--   user_id: 671b32e8-60eb-448a-8167-106bf835297f
--   Bands:
--     - Open Mic (6740246d-ba9b-493e-936d-ba733ce2101d)
--     - The Second Summer (6d71a662-f1a4-4fb9-a611-9b2c8e7716d3)
--     - Toxic Crayon (003be463-e63a-4ec5-b152-4f64c60afcbf)
--   One Calendar Feature Deployed: 2026-06-26 (events before this need backfill)
-- ============================================================================

WITH tony_bands AS (
  -- Tony's 3 active bands with names
  SELECT 
    '6740246d-ba9b-493e-936d-ba733ce2101d'::uuid as band_id, 
    'Open Mic' as band_name
  UNION ALL
  SELECT 
    '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3'::uuid, 
    'The Second Summer'
  UNION ALL
  SELECT 
    '003be463-e63a-4ec5-b152-4f64c60afcbf'::uuid, 
    'Toxic Crayon'
),
tony_historical_events AS (
  -- Tony's gigs (before One Calendar feature)
  SELECT 
    g.date as event_date,
    g.band_id as origin_band_id,
    b.name as origin_band_name,
    'Gig: ' || g.name as event_description
  FROM gigs g
  JOIN bands b ON b.id = g.band_id
  WHERE g.band_id IN (
    '6740246d-ba9b-493e-936d-ba733ce2101d',
    '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3',
    '003be463-e63a-4ec5-b152-4f64c60afcbf'
  )
  AND g.created_at < '2026-06-26'
  AND g.is_potential = false

  UNION ALL

  -- Tony's rehearsals (before One Calendar feature)
  SELECT 
    r.date as event_date,
    r.band_id as origin_band_id,
    b.name as origin_band_name,
    'Rehearsal at ' || r.location as event_description
  FROM rehearsals r
  JOIN bands b ON b.id = r.band_id
  WHERE r.band_id IN (
    '6740246d-ba9b-493e-936d-ba733ce2101d',
    '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3',
    '003be463-e63a-4ec5-b152-4f64c60afcbf'
  )
  AND r.created_at < '2026-06-26'
  AND r.is_potential = false
),
missing_blocks AS (
  -- Cross-join events with bands, then aggregate to handle same-day collisions
  SELECT
    te.event_date,
    string_agg(DISTINCT te.event_description, '; ' ORDER BY te.event_description) as event_description,
    string_agg(DISTINCT te.origin_band_name, ', ' ORDER BY te.origin_band_name) as origin_band_name,
    tb.band_name as target_band_name,
    tb.band_id as target_band_id,
    'Unavailable (scheduled with ' || 
      string_agg(DISTINCT te.origin_band_name, ', ' ORDER BY te.origin_band_name) || 
      ')' as reason
  FROM tony_historical_events te
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != te.origin_band_id  -- Don't block the origin band
  AND NOT EXISTS (
    -- Skip rows that already exist in block_dates
    SELECT 1 FROM block_dates bd
    WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
      AND bd.band_id = tb.band_id
      AND bd.date = te.event_date
  )
  GROUP BY tb.band_id, tb.band_name, te.event_date
)
-- Show all rows that would be inserted
SELECT
  event_date,
  event_description,
  origin_band_name,
  target_band_name,
  reason
FROM missing_blocks
ORDER BY event_date DESC, origin_band_name, target_band_name;

-- Summary counts (uncomment to see aggregate stats instead of full list)
-- SELECT
--   COUNT(*) as total_rows_to_insert,
--   COUNT(DISTINCT event_date) as unique_dates,
--   COUNT(DISTINCT target_band_name) as bands_affected
-- FROM missing_blocks;
