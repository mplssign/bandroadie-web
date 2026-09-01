-- Verify Tony's current active band membership
-- Purpose: Confirm which bands Tony is currently a member of before running diagnostic queries
-- This replaces the hardcoded band list used earlier in the investigation

SELECT
  bm.band_id,
  b.name as band_name,
  bm.role,
  bm.status,
  bm.joined_at
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
  AND bm.status = 'active'
ORDER BY bm.joined_at;
