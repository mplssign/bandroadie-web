-- DRY-RUN: Supplemental backfill for Task 3 gap period (Jun 26 → Jul 7)
-- 
-- CONTEXT:
-- - "The Little Owl Social Pub" gig (Open Mic, event date 2026-07-09) was created on 2026-07-07 09:04:29
-- - This was BEFORE commit e3e60ec deployed gig auto-blocking (2026-07-07 22:56:04)
-- - Auto-conflict-blocking did not run for this gig
-- - Task 3 diagnostics confirmed missing block: The Second Summer, 2026-07-09
-- 
-- SCOPE: Exactly 1 missing block row
-- 
-- STATUS: DRY-RUN ONLY — Do NOT execute until Manager approves
-- 
-- Tony's bands:
-- - Open Mic (origin band for this gig): 6740246d-ba9b-493e-936d-ba733ce2101d
-- - The Second Summer (missing block): 6d71a662-f1a4-4fb9-a611-9b2c8e7716d3
-- - Toxic Crayon (already has block): 003be463-e63a-4ec5-b152-4f64c60afcbf

-- DRY-RUN: Verify row is still absent before executing INSERT
SELECT
  '671b32e8-60eb-448a-8167-106bf835297f'::uuid as user_id,
  '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3'::uuid as band_id,
  '2026-07-09'::date as date,
  'Unavailable (scheduled with Open Mic)' as reason,
  NOT EXISTS (
    SELECT 1 FROM block_dates
    WHERE user_id = '671b32e8-60eb-448a-8167-106bf835297f'
      AND band_id = '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3'
      AND date = '2026-07-09'
  ) as would_insert;

-- Expected: would_insert = true (row still missing, safe to insert)
-- If would_insert = false, STOP — something already filled the gap since Task 3 diagnostic ran
-- 
-- To execute (after Manager approval), replace above SELECT with:
-- 
-- INSERT INTO block_dates (user_id, band_id, date, reason, created_at, updated_at)
-- VALUES (
--   '671b32e8-60eb-448a-8167-106bf835297f',
--   '6d71a662-f1a4-4fb9-a611-9b2c8e7716d3',
--   '2026-07-09',
--   'Unavailable (scheduled with Open Mic)',
--   now(),
--   now()
-- )
-- ON CONFLICT (user_id, band_id, date) DO NOTHING;
