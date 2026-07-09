-- Task 2: Investigate partial-block anomaly from "Test Gig 2" (2026-07-26)
-- Expected: 2 target bands, but only 1 block row written
-- Query: Find all block_dates for stubbymalone@gmail.com on 2026-07-26
--
-- ARCHITECTURE GATE CORRECTION: Test gig was created under a non-admin test account
--   (stubbymalone@gmail.com / 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925), NOT Tony's account.
--   Console log confirmed: "Auto-blocking 1 date(s) for user: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925"
--   Previous diagnostics checking Tony's user_id were invalid and have been discarded.
--
-- NOTE: Gig was created in band "The Banana Stand" (e89bea44-8dd4-4e3d-b527-c0f75e94aa7d)
--       Console log showed "Apply to all bands: 2 bands"
--       This query dynamically resolves stubbymalone's CURRENT active bands to ensure accuracy
--
-- PREREQUISITE: Run verify_stubbymalone_email_id_mapping.sql first to confirm user_id

WITH stubbymalone_bands AS (
  -- Dynamically fetch stubbymalone's current active bands
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
    AND bm.status = 'active'
)
SELECT
  sb.band_name,
  sb.band_id,
  bd.id as block_id,
  bd.date,
  bd.reason,
  bd.created_at,
  CASE 
    WHEN sb.band_id = 'e89bea44-8dd4-4e3d-b527-c0f75e94aa7d' THEN 'ORIGIN (gig created here)'
    WHEN bd.id IS NOT NULL THEN 'HAS BLOCK'
    ELSE 'MISSING BLOCK'
  END as status
FROM stubbymalone_bands sb
LEFT JOIN block_dates bd ON bd.band_id = sb.band_id
  AND bd.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
  AND bd.date = '2026-07-26'
ORDER BY sb.band_name;

-- Summary (separate statement with its own WITH clause)
WITH stubbymalone_bands AS (
  -- Dynamically fetch stubbymalone's current active bands (redeclared for this statement)
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
    AND bm.status = 'active'
)
SELECT
  COUNT(*) as total_bands,
  COUNT(*) FILTER (WHERE sb.band_id != 'e89bea44-8dd4-4e3d-b527-c0f75e94aa7d') as expected_target_bands,
  COUNT(*) FILTER (WHERE sb.band_id != 'e89bea44-8dd4-4e3d-b527-c0f75e94aa7d' AND bd.id IS NOT NULL) as blocks_created
FROM stubbymalone_bands sb
LEFT JOIN block_dates bd ON bd.band_id = sb.band_id
  AND bd.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
  AND bd.date = '2026-07-26';
