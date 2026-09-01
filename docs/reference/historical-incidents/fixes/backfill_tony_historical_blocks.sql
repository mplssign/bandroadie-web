-- ============================================================================
-- BACKFILL: Create cross-band block_dates for Tony's historical events
-- ============================================================================
-- Purpose: Insert missing block_dates for events created before One Calendar
--          feature was deployed (2026-06-26).
-- 
-- ⚠️  DO NOT RUN THIS UNTIL:
--     1. Dry-run query (backfill_tony_historical_blocks_dryrun.sql) has been reviewed
--     2. Tony has explicitly approved the exact row count and list
--     3. This script is tested on staging/dev environment first
--
-- Rollback SQL (if needed):
--   DELETE FROM block_dates 
--   WHERE user_id = '671b32e8-60eb-448a-8167-106bf835297f'
--     AND created_at > '[timestamp_when_backfill_ran]'
--     AND reason LIKE 'Unavailable (scheduled with %';
--
-- Tony's Details:
--   user_id: 671b32e8-60eb-448a-8167-106bf835297f
--   Bands:
--     - Open Mic (6740246d-ba9b-493e-936d-ba733ce2101d)
--     - The Second Summer (6d71a662-f1a4-4fb9-a611-9b2c8e7716d3)
--     - Toxic Crayon (003be463-e63a-4ec5-b152-4f64c60afcbf)
--   One Calendar Feature Deployed: 2026-06-26
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
    '671b32e8-60eb-448a-8167-106bf835297f'::uuid as user_id,
    tb.band_id as band_id,
    te.event_date as date,
    'Unavailable (scheduled with ' || 
      string_agg(DISTINCT te.origin_band_name, ', ' ORDER BY te.origin_band_name) || 
      ')' as reason
  FROM tony_historical_events te
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != te.origin_band_id  -- Don't block the origin band
  AND NOT EXISTS (
    -- Skip rows that already exist (makes this idempotent)
    SELECT 1 FROM block_dates bd
    WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
      AND bd.band_id = tb.band_id
      AND bd.date = te.event_date
  )
  GROUP BY tb.band_id, te.event_date
),
inserted AS (
  -- Insert missing block_dates and capture what was inserted
  INSERT INTO block_dates (user_id, band_id, date, reason)
  SELECT user_id, band_id, date, reason
  FROM missing_blocks
  ON CONFLICT (user_id, band_id, date) DO NOTHING
  RETURNING *
)
-- Return summary of what was inserted
SELECT 
  COUNT(*) as rows_inserted,
  COUNT(DISTINCT date) as unique_dates,
  COUNT(DISTINCT band_id) as bands_affected
FROM inserted;
