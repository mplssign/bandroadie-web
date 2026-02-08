-- Run this in Supabase SQL Editor to check your band member record
-- Replace YOUR_EMAIL with your actual email

SELECT 
  bm.id as member_id,
  bm.band_id,
  bm.user_id,
  bm.role,
  bm.status,
  b.name as band_name,
  u.email
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
JOIN auth.users u ON u.id = bm.user_id
WHERE u.email = 'YOUR_EMAIL';
