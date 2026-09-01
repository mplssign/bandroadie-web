-- Inspect existing Toxic Crayon block_dates row for 2026-07-09
-- Context: Task 3 gap analysis found "The Little Owl Social Pub" gig (Open Mic, created 2026-07-07 09:04:29)
--          should have created blocks in both The Second Summer and Toxic Crayon.
--          Toxic Crayon already has a block for this date. Need to determine if it was caused by this gig
--          (partial propagation success) or by a different event (coincidental date overlap).

SELECT
  bd.id as block_id,
  bd.user_id,
  bd.band_id,
  b.name as band_name,
  bd.date,
  bd.reason,
  bd.created_at,
  -- Check if created_at is close to gig's created_at (2026-07-07 09:04:29)
  -- If within a few seconds, likely caused by this gig
  CASE
    WHEN bd.created_at >= '2026-07-07 09:04:20' AND bd.created_at <= '2026-07-07 09:04:40' THEN 'LIKELY CAUSED BY THIS GIG'
    ELSE 'DIFFERENT SOURCE (check other events on this date)'
  END as source_analysis
FROM block_dates bd
JOIN bands b ON b.id = bd.band_id
WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
  AND bd.band_id = '003be463-e63a-4ec5-b152-4f64c60afcbf'  -- Toxic Crayon
  AND bd.date = '2026-07-09';

-- If this returns a row with created_at near 2026-07-07 09:04:29, it means auto-conflict-blocking
-- partially succeeded (Toxic Crayon got the block, but The Second Summer was missed).
-- If created_at is significantly different, the block came from a different event.
