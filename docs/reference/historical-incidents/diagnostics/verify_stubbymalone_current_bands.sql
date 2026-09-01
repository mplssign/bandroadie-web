-- Verify stubbymalone's current active band membership
-- Purpose: Confirm which bands stubbymalone@gmail.com is currently a member of
-- This user created "Test Gig 2" in band "The Banana Stand" (e89bea44-8dd4-4e3d-b527-c0f75e94aa7d)
--
-- PREREQUISITE: Run verify_stubbymalone_email_id_mapping.sql first to confirm user_id is correct

SELECT
  bm.band_id,
  b.name as band_name,
  bm.role,
  bm.status,
  bm.joined_at
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
  AND bm.status = 'active'
ORDER BY bm.joined_at;

-- Expected: Should show "The Banana Stand" (e89bea44-8dd4-4e3d-b527-c0f75e94aa7d) as an active band
