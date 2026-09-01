-- Task 3: Investigate Jun 26 → Jul 7 gig backfill gap
-- Query gigs created between One Calendar launch (2026-06-26) and gig auto-block code deploy (2026-07-07 22:56:04)
-- Cross-check against block_dates to find missing cross-band blocks
--
-- NOTE: This query dynamically resolves Tony's CURRENT active bands to ensure correctness
--       regardless of membership changes since the gap period

WITH tony_bands AS (
  -- Dynamically fetch Tony's current active bands
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
    AND bm.status = 'active'
),
gap_gigs AS (
  -- Fetch gigs created during the gap period in Tony's current bands
  SELECT
    g.id,
    g.band_id,
    b.name as band_name,
    g.name as gig_name,
    g.date,
    g.created_at,
    g.is_potential
  FROM gigs g
  JOIN bands b ON b.id = g.band_id
  WHERE g.band_id IN (SELECT band_id FROM tony_bands)
  AND g.created_at >= '2026-06-26 00:00:00'
  AND g.created_at < '2026-07-07 22:56:04'
  AND g.is_potential = false
  ORDER BY g.created_at
),
missing_blocks AS (
  SELECT
    gg.date as event_date,
    gg.band_name as origin_band,
    gg.gig_name as event_name,
    gg.created_at as event_created_at,
    tb.band_name as target_band,
    tb.band_id as target_band_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM block_dates bd
        WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
          AND bd.band_id = tb.band_id
          AND bd.date = gg.date
      ) THEN 'EXISTS'
      ELSE 'MISSING'
    END as block_status
  FROM gap_gigs gg
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != gg.band_id  -- Don't check origin band
)
SELECT
  event_date,
  event_name,
  origin_band,
  target_band,
  block_status,
  event_created_at
FROM missing_blocks
ORDER BY event_date, origin_band, target_band;

-- Summary count (separate statement with its own WITH clause)
WITH tony_bands AS (
  -- Dynamically fetch Tony's current active bands (redeclared for this statement)
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
    AND bm.status = 'active'
),
gap_gigs AS (
  -- Fetch gigs created during the gap period (redeclared for this statement)
  SELECT
    g.id,
    g.band_id,
    b.name as band_name,
    g.name as gig_name,
    g.date,
    g.created_at,
    g.is_potential
  FROM gigs g
  JOIN bands b ON b.id = g.band_id
  WHERE g.band_id IN (SELECT band_id FROM tony_bands)
  AND g.created_at >= '2026-06-26 00:00:00'
  AND g.created_at < '2026-07-07 22:56:04'
  AND g.is_potential = false
  ORDER BY g.created_at
)
SELECT
  block_status,
  COUNT(*) as count
FROM (
  SELECT
    gg.date as event_date,
    tb.band_id as target_band_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM block_dates bd
        WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
          AND bd.band_id = tb.band_id
          AND bd.date = gg.date
      ) THEN 'EXISTS'
      ELSE 'MISSING'
    END as block_status
  FROM gap_gigs gg
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != gg.band_id
) subq
GROUP BY block_status;
